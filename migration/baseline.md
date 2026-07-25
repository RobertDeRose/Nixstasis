# Legacy workflow baseline

Generated: `2026-07-25T02:22:41+00:00`

## Documentation

- Status: `passed`
- Command: `1 named partition(s)`
- Note: See validation_partitions for command ownership and evidence.

## Tests

- Status: `passed`
- Command: `2 named partition(s)`
- Note: See validation_partitions for command ownership and evidence.

## Hk

- Status: `evaluable`
- Command: `pkl eval hk.pkl`
- Note: Pkl evaluation passed.

## Resolution

- Write eligible: `true`
- Unresolved: none
- Resolution flags: documentation=supplied; tests=supplied
- Uncovered candidates: none
- Residual limitations: none

## Validation partitions

- `root-mise-docs-build` (documentation): status=`passed`; argv=`mise run docs:build`; cwd=`.`; provenance=`mise.toml`
  - Return code: `0`; output truncated: `false`
  - stdout:
        (empty)
  - stderr:
         INFO Book building has started
         INFO Running the html backend
         INFO HTML book written to `/Users/DeRoseR/workspace/personal/nixstasis.chore-migrate-dstack-workflow-20260725T021757Z/docs/../book`
- `client-mise-test` (tests): status=`passed`; argv=`mise run //packages/client:test`; cwd=`.`; provenance=`packages/client/mise.toml`
  - Return code: `0`; output truncated: `false`
  - stdout:
        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/cmd/nixstasis[0m[0;37m (40.9% coverage)[0m
          [0;32m✅ TestGivenCommands_WhenHandleCommandResponses_ThenResultsSent[0;37m (0s)[0m
          [0;32m✅ TestGivenInvalidScript_WhenTestScriptRuns_ThenExitNonZeroAndNoYAMLOutput[0;37m (10ms)[0m
          [0;32m✅ TestGivenReplCommand_WhenRun_ThenBuiltinsAvailable[0;37m (0s)[0m
          [0;32m✅ TestGivenScriptFile_WhenListInstallRemove_ThenLifecycleSucceeds[0;37m (10ms)[0m
        NAME         VERSION  PATH
        test_script           /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestGivenScriptFile_WhenListInstallRemove_ThenLifecycleSucceeds1152411709/001/source.stary
        Installed test_script at /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestGivenScriptFile_WhenListInstallRemove_ThenLifecycleSucceeds1152411709/001/.config/nixstasis/scripts/test_script.stary
        Removed test_script
          [0;32m✅ TestGivenValidScript_WhenTestScriptRuns_ThenYAMLOutputPrinted[0;37m (10ms)[0m
          [0;32m✅ TestHydrateCommandPayloadsUsesBoundedParallelism[0;37m (40ms)[0m
          [0;32m✅ TestInitialCommandPolicyUsesPersistedServerPolicyBeforeLocalConfig[0;37m (30ms)[0m
          [0;32m✅ TestPollIntervalUsesConfiguredValue[0;37m (0s)[0m
          [0;32m✅ TestPollOnceDoesNothingWhenTokenAbsentAndFRPInactive[0;37m (0s)[0m
        2026/07/24 22:19:01 INFO polled using 0 scripts in 0 ms
          [0;32m✅ TestPollOnceKeepsActiveFRPWhenTokenPresent[0;37m (0s)[0m
        2026/07/24 22:19:01 INFO polled using 0 scripts in 0 ms
          [0;32m✅ TestPollOnceRestartsActiveFRPWhenTokenChanges[0;37m (0s)[0m
        2026/07/24 22:19:01 INFO polled using 0 scripts in 0 ms
        2026/07/24 22:19:01 INFO Server remote access token changed, restarting FRP
        2026/07/24 22:19:01 INFO Server requested remote access, starting FRP
          [0;32m✅ TestPollOnceRestartsActiveFRPWhenTokenStateUnknown[0;37m (0s)[0m
        2026/07/24 22:19:01 INFO polled using 0 scripts in 0 ms
        2026/07/24 22:19:01 INFO Server remote access token state unknown, restarting FRP
        2026/07/24 22:19:01 INFO Server requested remote access, starting FRP
          [0;32m✅ TestPollOnceStartsFRPWithRemoteAccessToken[0;37m (0s)[0m
        2026/07/24 22:19:01 INFO polled using 0 scripts in 0 ms
        2026/07/24 22:19:01 INFO Server requested remote access, starting FRP
          [0;32m✅ TestPollOnceStopsFRPWhenRemoteAccessTokenAbsent[0;37m (0s)[0m
        2026/07/24 22:19:01 INFO polled using 0 scripts in 0 ms
        2026/07/24 22:19:01 INFO Server disabled remote access, stopping FRP
          [0;32m✅ TestPollResponseTokenOverridesRuntimeFRPAuthToken[0;37m (0s)[0m
          [0;33m🚧 TestRunFRPSession_ContextCancellation[0;37m (0s)[0m
            frp_session_test.go:107: full cancellation test requires refactoring runFRPSession to accept context
          [0;32m✅ TestRunFRPSession_FRPCFailure[0;37m (30ms)[0m
        2026/07/24 22:19:00 INFO Starting FRP session config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestRunFRPSession_FRPCFailure2908960879/001/frpc.toml timeout=1h0m0s
          [0;32m✅ TestRunFRPSession_MissingBinary[0;37m (0s)[0m
          [0;32m✅ TestRunFRPSession_MissingConfig[0;37m (0s)[0m
          [0;32m✅ TestRunFRPSession_SuccessfulRun[0;37m (10ms)[0m
        2026/07/24 22:19:00 INFO Starting FRP session config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestRunFRPSession_SuccessfulRun1530353978/001/frpc.toml timeout=1h0m0s
        2026/07/24 22:19:00 INFO FRP session ended normally
          [0;32m✅ TestRunFRPSession_UsesExplicitPaths[0;37m (10ms)[0m
        2026/07/24 22:19:00 INFO Starting FRP session config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestRunFRPSession_UsesExplicitPaths1256050727/001/frpc.toml timeout=1h0m0s
        2026/07/24 22:19:00 INFO FRP session ended normally
          [0;32m✅ TestRuntimeFRPConfigFallsBackToGeneratedDeviceIDNameOnly[0;37m (0s)[0m
          [0;32m✅ TestRuntimeFRPConfigPreservesConfiguredValuesExceptAuthToken[0;37m (0s)[0m

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/commandpolicy[0m[0;37m (67.2% coverage)[0m
          [0;32m✅ TestStoreLoadMissingReturnsErrNoPolicy[0;37m (0s)[0m
          [0;32m✅ TestStoreSaveLoadRoundTrip[0;37m (30ms)[0m

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/commands[0m[0;37m (80.3% coverage)[0m
          [0;32m✅ TestGivenApplyCommandPolicyPersistFailure_WhenExecuteBatch_ThenFailsClosed[0;37m (10ms)[0m
          [0;32m✅ TestGivenApplyCommandPolicyStore_WhenExecuteBatch_ThenPersistsPolicy[0;37m (30ms)[0m
          [0;32m✅ TestGivenApplyCommandPolicy_WhenExecuteBatch_ThenAppliesPolicy[0;37m (0s)[0m
          [0;32m✅ TestGivenBadApplyCommandPolicyPayload_WhenExecuteBatch_ThenFails[0;37m (0s)[0m
          [0;32m✅ TestGivenConfiguredScriptsDir_WhenInstallScript_ThenWritesThere[0;37m (0s)[0m
          [0;32m✅ TestGivenDeferredRunScriptPayload_WhenExecuteBatch_ThenFailsClosed[0;37m (0s)[0m
          [0;32m✅ TestGivenDuplicateApplyCommandPolicyVersion_WhenExecuteBatch_ThenReportsIdempotent[0;37m (0s)[0m
          [0;32m✅ TestGivenDuplicateCommandID_WhenExecuteBatch_ThenLaterDuplicateFails[0;37m (0s)[0m
          [0;32m✅ TestGivenEmptyApplyCommandPolicy_WhenExecuteBatch_ThenAppliesDenyAll[0;37m (20ms)[0m
          [0;32m✅ TestGivenExpiredContext_WhenExecuteBatch_ThenTimeoutReported[0;37m (0s)[0m
          [0;32m✅ TestGivenInstallCommitAndExpiredContext_WhenExecuteBatch_ThenSuccessReported[0;37m (0s)[0m
          [0;32m✅ TestGivenInvalidRunScriptPayload_WhenExecuteBatch_ThenReturnsFailedEnvelope[0;37m (0s)[0m
          [0;32m✅ TestGivenOlderApplyCommandPolicyRevision_WhenExecuteBatch_ThenRejectsStalePolicy[0;37m (0s)[0m
          [0;32m✅ TestGivenOversizedCommandList_WhenExecuteBatch_ThenOnlyMaxAccepted[0;37m (0s)[0m
          [0;32m✅ TestGivenPathTraversalScriptName_WhenInstallScript_ThenFails[0;37m (0s)[0m
          [0;32m✅ TestGivenPathTraversalScriptVersion_WhenRemoveScript_ThenFails[0;37m (0s)[0m
          [0;32m✅ TestGivenPreloadedRuntimePolicy_WhenExecuteBatch_ThenSameVersionReplayIsIdempotent[0;37m (0s)[0m
          [0;32m✅ TestGivenRemoveCommitAndExpiredContext_WhenExecuteBatch_ThenSuccessReported[0;37m (10ms)[0m
          [0;32m✅ TestGivenRunScriptPolicyApplied_WhenExecuteBatch_ThenCanRunAllowedCommand[0;37m (1.88s)[0m
          [0;32m✅ TestGivenRunScript_WhenExecuteBatch_ThenDoesNotTouchInstalledScripts[0;37m (0s)[0m
          [0;32m✅ TestGivenValidRunScriptPayload_WhenExecuteBatch_ThenReturnsStructuredResult[0;37m (0s)[0m
          [0;32m✅ TestSSHAuthorizeRejectsInvalidDynamicPayloads[0;37m (0s)[0m
          [0;32m✅ TestSSHAuthorizeRejectsInvalidDynamicPayloads/invalid_ttl[0;37m (0s)[0m
          [0;32m✅ TestSSHAuthorizeRejectsInvalidDynamicPayloads/malformed_json[0;37m (0s)[0m
          [0;32m✅ TestSSHAuthorizeRejectsInvalidDynamicPayloads/missing_session[0;37m (0s)[0m
          [0;32m✅ TestSSHAuthorizeRejectsInvalidDynamicPayloads/wrong_user[0;37m (0s)[0m
          [0;32m✅ TestSSHAuthorizeStoresDynamicKeyInMemory[0;37m (0s)[0m
          [0;32m✅ TestSSHRevokeFailsWithoutSessionRef[0;37m (0s)[0m
          [0;32m✅ TestSSHRevokeIsSerial[0;37m (0s)[0m
          [0;32m✅ TestSSHRevokeRemovesStoredAuthorization[0;37m (0s)[0m
          [0;32m✅ TestSSHRevokeResolvesSessionRefFromData[0;37m (0s)[0m

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/config[0m[0;37m (85.2% coverage)[0m
          [0;32m✅ TestLoadCanUseExplicitConfigFile[0;37m (10ms)[0m
          [0;32m✅ TestPathsCanBeOverriddenForLocalDevelopment[0;37m (0s)[0m
          [0;32m✅ TestPathsUseNixstasisDefaults[0;37m (0s)[0m

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/e2e[0m[0;37m (36.7% coverage)[0m
          [0;32m✅ TestRunSuiteOverridesJourneys[0;37m (10ms)[0m
          [0;32m✅ TestRunSuiteUsesConfiguredJourneys[0;37m (10ms)[0m
          [0;32m✅ TestRunSuiteWritesV1JourneyLogs[0;37m (10ms)[0m
          [0;32m✅ TestRuntimePayloadRefUsesDeviceAPIKey[0;37m (0s)[0m
          [0;32m✅ TestSelectJourneysRejectsUnknown[0;37m (0s)[0m
          [0;32m✅ TestSelectJourneysUsesAllWhenEmpty[0;37m (0s)[0m

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/frp[0m[0;37m (87.6% coverage)[0m
          [0;32m✅ TestFRPCTemplateEnv[0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr[0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr/#00[0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr/0.0.0.0[0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr/127.0.0.1[0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr/192.168.1.1[0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr/::1[0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr/[::1][0;37m (0s)[0m
          [0;32m✅ TestLoopbackAddr/localhost[0;37m (0s)[0m
          [0;32m✅ TestManager_GetStatus[0;37m (20ms)[0m
          [0;32m✅ TestManager_StartStop[0;37m (90ms)[0m
        2026/07/24 22:19:02 INFO Starting FRP tunnel config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestManager_StartStop1510431772/002/frpc.toml name=atom-aabbcc
        2026/07/24 22:19:02 INFO FRP transient service started unit=nixstasis-frpc
        2026/07/24 22:19:02 INFO Stopping FRP tunnel
        2026/07/24 22:19:02 INFO FRP transient service stopped
          [0;32m✅ TestPackagedConfigExampleProvidesFRPName[0;37m (0s)[0m
          [0;32m✅ TestPackagedConfigUsesQuotedPlaceholders[0;37m (0s)[0m
          [0;32m✅ TestPackagedSimulatorHTTPAssets[0;37m (0s)[0m
          [0;32m✅ TestStart_NoWaitFlag[0;37m (30ms)[0m
        2026/07/24 22:19:02 INFO Starting FRP tunnel config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestStart_NoWaitFlag2042520545/002/frpc.toml name=atom-aabbcc
        2026/07/24 22:19:02 INFO FRP transient service started unit=nixstasis-frpc
          [0;32m✅ TestStart_RejectsEmptyAuthToken[0;37m (0s)[0m
          [0;32m✅ TestStart_RejectsEmptyName[0;37m (10ms)[0m
          [0;32m✅ TestStart_RejectsEmptyServerAddr[0;37m (0s)[0m
          [0;32m✅ TestStart_RejectsInvalidHTTPLocalAddr[0;37m (0s)[0m
          [0;32m✅ TestStart_RejectsInvalidPorts[0;37m (10ms)[0m
          [0;32m✅ TestStart_RejectsNonLoopbackWebServerAddr[0;37m (0s)[0m
          [0;32m✅ TestStart_RemovesAuthTokenEnvironmentFileWhenSystemdRunFails[0;37m (20ms)[0m
        2026/07/24 22:19:02 INFO Starting FRP tunnel config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestStart_RemovesAuthTokenEnvironmentFileWhenSystemdRunFails2819340537/002/frpc.toml name=atom-aabbcc
          [0;32m✅ TestStart_RequiresSystemd[0;37m (10ms)[0m
          [0;32m✅ TestStart_SystemdRunArgs[0;37m (30ms)[0m
        2026/07/24 22:19:02 INFO Starting FRP tunnel config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestStart_SystemdRunArgs1698328471/002/frpc.toml name=atom-aabbcc
        2026/07/24 22:19:02 INFO FRP transient service started unit=nixstasis-frpc
          [0;32m✅ TestStart_WritesAuthTokenEnvironmentFile[0;37m (30ms)[0m
        2026/07/24 22:19:02 INFO Starting FRP tunnel config=/var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/TestStart_WritesAuthTokenEnvironmentFile1180135253/002/frpc.toml name=atom-aabbcc
        2026/07/24 22:19:02 INFO FRP transient service started unit=nixstasis-frpc
          [0;32m✅ TestSystemdRunEnv_MinimalEnv[0;37m (0s)[0m

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/identity[0m[0;37m (33.6% coverage)[0m
          [0;32m✅ TestGetPrimaryIP[0;37m (0s)[0m
            detect_test.go:41: Detected IP: 10.0.0.197
          [0;32m✅ TestGetPrimaryMAC[0;37m (0s)[0m
            detect_test.go:23: Detected MAC: fa:76:47:19:91:d3
          [0;32m✅ TestLoadUUIDNormalizesValidIdentity[0;37m (0s)[0m
          [0;32m✅ TestLoadUUIDRejectsEmptyIdentityFile[0;37m (0s)[0m
          [0;32m✅ TestLoadUUIDRejectsInvalidIdentityFile[0;37m (0s)[0m
          [0;32m✅ TestLoadUUIDReturnsErrNoIdentityWhenFileMissing[0;37m (0s)[0m

        [0;31m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/logging[0m
        	github.com/RobertDeRose/Nixstasis/packages/client/internal/logging		coverage: 0.0% of statements

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/script[0m[0;37m (49.7% coverage)[0m
          [0;32m✅ TestAcceptCriteriaMatchesOnlyExpectedKeyValues[0;37m (0s)[0m
          [0;32m✅ TestCompileSchema[0;37m (0s)[0m
          [0;32m✅ TestExecCmdDoesNotPassUnrelatedEnvironment[0;37m (680ms)[0m
          [0;32m✅ TestExecCmdProvidesNormalizedDefaultEnvironment[0;37m (240ms)[0m
          [0;32m✅ TestExecCmdRejectsPathShadowedCommands[0;37m (10ms)[0m
          [0;32m✅ TestExecCmdRequiresCapability[0;37m (0s)[0m
          [0;32m✅ TestExecCmdRunsAllowlistedCommandWithSanitizedEnvironment[0;37m (240ms)[0m
          [0;32m✅ TestExecCmdSanitizesHighRiskEnvironment[0;37m (250ms)[0m
          [0;32m✅ TestGivenCanceledContext_WhenExecuteScripts_ThenReturnsTimeoutStatus[0;37m (10ms)[0m
          [0;32m✅ TestGivenInvalidFrontMatter_WhenExecuteScripts_ThenReturnsError[0;37m (10ms)[0m
          [0;32m✅ TestGivenNameSelector_WhenResolveScript_ThenReturnsMatchingScript[0;37m (0s)[0m
          [0;32m✅ TestGivenPathSelector_WhenResolveScript_ThenReturnsMatchingScript[0;37m (20ms)[0m
          [0;32m✅ TestGivenSchemaMismatch_WhenExecuteScripts_ThenReturnsValidationError[0;37m (10ms)[0m
          [0;32m✅ TestGivenSlowScript_WhenExecuteScripts_ThenAddsWarning[0;37m (10ms)[0m
          [0;32m✅ TestGivenValidScript_WhenExecuteScripts_ThenReturnsValidatedOutput[0;37m (10ms)[0m
          [0;32m✅ TestMQTTTopicRestrictions[0;37m (0s)[0m
          [0;32m✅ TestParseAcceptCriteriaRejectsNestedSelectors[0;37m (0s)[0m
          [0;32m✅ TestParseStaryContent[0;37m (0s)[0m
          [0;32m✅ TestPubAndGetRequiresMQTTCapability[0;37m (0s)[0m
          [0;32m✅ TestReportEnvelope[0;37m (0s)[0m
          [0;32m✅ TestRuntimeTimeoutCancelsRunawayScript[0;37m (10ms)[0m
          [0;32m✅ TestRuntimeTimeoutOnCanceledContext[0;37m (0s)[0m

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/sshauth[0m[0;37m (4.9% coverage)[0m
          [0;32m✅ TestChownSocketGroupIgnoresMissingOptionalGroup[0;37m (0s)[0m
          [0;32m✅ TestChownSocketGroupReturnsChownFailure[0;37m (0s)[0m
          [0;32m✅ TestChownSocketGroupReturnsLookupFailure[0;37m (0s)[0m
          [0;33m🚧 TestRealSSHDIntegration[0;37m (0s)[0m
            sshd_integration_test.go:38: sshd integration test is Linux-only (CI)

        [0;33m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/telemetry[0m
          🛑 no test files

        [0;32m📦 github.com/RobertDeRose/Nixstasis/packages/client/internal/transport[0m[0;37m (76.9% coverage)[0m
          [0;32m✅ TestCommandEndpointsUseRuntimeV1Routes[0;37m (0s)[0m
          [0;32m✅ TestPollUsesHeartbeatContract[0;37m (0s)[0m
          [0;32m✅ TestRegisterDevice[0;37m (10ms)[0m
          [0;32m✅ TestRegisterDevice/Empty_ID_Response[0;37m (0s)[0m
          [0;32m✅ TestRegisterDevice/Invalid_Response_Body[0;37m (0s)[0m
          [0;32m✅ TestRegisterDevice/Server_Error[0;37m (0s)[0m
          [0;32m✅ TestRegisterDevice/Success[0;37m (0s)[0m

        [0;31m📦 github.com/RobertDeRose/Nixstasis/packages/client/scripts/e2e[0m
        	github.com/RobertDeRose/Nixstasis/packages/client/scripts/e2e		coverage: 0.0% of statements

        [0;31m📦 github.com/RobertDeRose/Nixstasis/packages/client/scripts/mock_api[0m
        	github.com/RobertDeRose/Nixstasis/packages/client/scripts/mock_api		coverage: 0.0% of statements

  - stderr:
        [//packages/client:test] $ go test -race --json -coverprofile=coverage.out ./..…
- `server-elixir-test` (tests): status=`passed`; argv=`mix test`; cwd=`packages/server`; provenance=`manifest-and-test-evidence`
  - Return code: `0`; output truncated: `false`
  - stdout:

        22:20:24.049 [info] Compiling file system watcher for Mac...

        22:20:25.744 [info] Done.
        ==> file_system
        Compiling 7 files (.ex)
        Generated file_system app
        ==> stream_data
        Compiling 3 files (.ex)
        Generated stream_data app
        ==> ymlr
        Compiling 3 files (.ex)
        Generated ymlr app
        ==> mime
        Compiling 1 file (.ex)
        Generated mime app
        ==> nimble_options
        Compiling 3 files (.ex)
        Generated nimble_options app
        ==> fine
        Compiling 1 file (.ex)
        Generated fine app
        ==> bunt
        Compiling 2 files (.ex)
        Generated bunt app
        ==> plug_crypto
        Compiling 5 files (.ex)
        Generated plug_crypto app
        ==> hpax
        Compiling 4 files (.ex)
        Generated hpax app
        ==> mint
        Compiling 1 file (.erl)
        Compiling 20 files (.ex)
        Generated mint app
        ==> nixstasis
        ===> Analyzing applications...
        ===> Compiling yamerl
        ==> ets
        Compiling 7 files (.ex)
        Generated ets app
        ==> table_rex
        Compiling 7 files (.ex)
        Generated table_rex app
        ==> iterex
        Compiling 48 files (.ex)
        Generated iterex app
        ==> elixir_make
        Compiling 8 files (.ex)
        Generated elixir_make app
        ==> conv_case
        Compiling 1 file (.ex)
        Generated conv_case app
        ==> sourceror
        Compiling 12 files (.ex)
        Generated sourceror app
        ==> decimal
        Compiling 4 files (.ex)
        Generated decimal app
        ==> jason
        Compiling 10 files (.ex)
        Generated jason app
        ==> esbuild
        Compiling 4 files (.ex)
        Generated esbuild app
        ==> spark
        Compiling 40 files (.ex)
        Generated spark app
        ==> xema
        Compiling 19 files (.ex)
        Generated xema app
        ==> yaml_elixir
        Compiling 6 files (.ex)
        Generated yaml_elixir app
        ==> libgraph
        Compiling 15 files (.ex)
        Generated libgraph app
        ==> nixstasis
        ===> Analyzing applications...
        ===> Compiling unicode_util_compat
        ===> Analyzing applications...
        ===> Compiling idna
        ===> Analyzing applications...
        ===> Compiling telemetry
        ==> telemetry_metrics
        Compiling 7 files (.ex)
        Generated telemetry_metrics app
        ==> nixstasis
        ===> Analyzing applications...
        ===> Compiling telemetry_poller
        ==> db_connection
        Compiling 18 files (.ex)
        Generated db_connection app
        ==> ecto
        Compiling 56 files (.ex)
        Generated ecto app
        ==> thousand_island
        Compiling 18 files (.ex)
        Generated thousand_island app
        ==> phoenix_html
        Compiling 6 files (.ex)
        Generated phoenix_html app
        ==> phoenix_template
        Compiling 4 files (.ex)
        Generated phoenix_template app
        ==> expo
        Compiling 2 files (.erl)
        Compiling 22 files (.ex)
        Generated expo app
        ==> gettext
        Compiling 18 files (.ex)
        Generated gettext app
        ==> phoenix_pubsub
        Compiling 12 files (.ex)
        Generated phoenix_pubsub app
        ==> json_xema
        Compiling 4 files (.ex)
        Generated json_xema app
        ==> dns_cluster
        Compiling 1 file (.ex)
        Generated dns_cluster app
        ==> phoenix_view
        Compiling 1 file (.ex)
        Generated phoenix_view app
        ==> splode
        Compiling 5 files (.ex)
        Generated splode app
        ==> reactor
        Compiling 113 files (.ex)
        Generated reactor app
        ==> credo
        Compiling 254 files (.ex)
        Generated credo app
        ==> plug
        Compiling 1 file (.erl)
        Compiling 42 files (.ex)
        Generated plug app
        ==> open_api_spex
        Compiling 80 files (.ex)
        Generated open_api_spex app
        ==> postgrex
        Compiling 69 files (.ex)
        Generated postgrex app
        ==> ecto_sql
        Compiling 25 files (.ex)
        Generated ecto_sql app
        ==> ecto_psql_extras
        Compiling 43 files (.ex)
        Generated ecto_psql_extras app
        ==> phoenix_ecto
        Compiling 7 files (.ex)
        Generated phoenix_ecto app
        ==> crux
        Compiling 19 files (.ex)
        Generated crux app
        ==> ash
        Compiling 549 files (.ex)
        Compiling lib/ash/reactor/reactor.ex (it's taking more than 10s)
        Generated ash app
        ==> ash_state_machine
        Compiling 17 files (.ex)
        Generated ash_state_machine app
        ==> ash_sql
        Compiling 14 files (.ex)
        Generated ash_sql app
        ==> ash_postgres
        Compiling 58 files (.ex)
        Generated ash_postgres app
        ==> nimble_pool
        Compiling 2 files (.ex)
        Generated nimble_pool app
        ==> finch
        Compiling 14 files (.ex)
        Generated finch app
        ==> req
        Compiling 19 files (.ex)
        Generated req app
        ==> cc_precompiler
        Compiling 3 files (.ex)
        Generated cc_precompiler app
        ==> lazy_html
        Compiling 3 files (.ex)
        Generated lazy_html app
        ==> tailwind
        Compiling 3 files (.ex)
        Generated tailwind app
        ==> websock
        Compiling 1 file (.ex)
        Generated websock app
        ==> bandit
        Compiling 54 files (.ex)
        Generated bandit app
        ==> swoosh
        Compiling 55 files (.ex)
        Generated swoosh app
        ==> websock_adapter
        Compiling 4 files (.ex)
        Generated websock_adapter app
        ==> phoenix
        Compiling 74 files (.ex)
        Generated phoenix app
        ==> ash_json_api
        Compiling 74 files (.ex)
        Generated ash_json_api app
        ==> phoenix_live_view
        Compiling 49 files (.ex)
        Generated phoenix_live_view app
        ==> ash_phoenix
        Compiling 35 files (.ex)
        Generated ash_phoenix app
        ==> ash_admin
        Compiling 39 files (.ex)
        Generated ash_admin app
        ==> phoenix_live_dashboard
        Compiling 36 files (.ex)
        Generated phoenix_live_dashboard app
        ==> nixstasis
        Compiling 158 files (.ex)
        Generated nixstasis app
        Getting extensions in current project...
        Running setup for AshPostgres.DataLayer...
        Running ExUnit with seed: 148067, max_cases: 20

        ....................................................................................................................................................................................Exported run to /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/e2e-export-static-1/pages/runs/v1.2.3/ddddddd
        Manifest entries: 1
        Exported run to /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/e2e-export-static-1/pages/runs/feature/d/eeeeeee
        Manifest entries: 2
        Exported run to /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/e2e-export-static-1/pages/runs/feature/e/fffffff
        Manifest entries: 2
        Purged runs: 1
        .Exported run to /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/e2e-export-static-2/pages/runs/main/abcdef1
        Manifest entries: 1
        .Exported run to /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/e2e-export-static-3/pages/runs/feature/a/aaaaaaa
        Manifest entries: 1
        Exported run to /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/e2e-export-static-3/pages/runs/feature/b/bbbbbbb
        Manifest entries: 2
        Exported run to /var/folders/6s/9d_7z_4d41b7n05ypfk6zds40000gp/T/e2e-export-static-3/pages/runs/feature/c/ccccccc
        Manifest entries: 2
        Purged runs: 1
        ..22:22:34.981 [warning] Browser request did not resolve to valid Nixstasis operator permissions
        ..22:22:34.983 [warning] Browser request did not resolve to valid Nixstasis operator permissions
        ............................................................Seeding baseline E2E data...
        ..Seeding baseline E2E data...
        ...Seeding baseline E2E data...
        ...Seeding baseline E2E data...
        .Seeding baseline E2E data...
        ..........Seeding baseline E2E data...
        .Seeding baseline E2E data...
        .Seeding baseline E2E data...
        ..Seeding baseline E2E data...
        ..........22:22:36.466 [error] Postgrex.Protocol (#PID<0.20881.0> ("db_conn_8")) disconnected: ** (DBConnection.ConnectionError) client #PID<0.22509.0> exited
        .......................Seeding baseline E2E data...
        .Seeding baseline E2E data...
        Seeding baseline E2E data...
        .Seeding baseline E2E data...
        ..Seeding baseline E2E data...
        ..........................................................................................22:22:38.580 [error] Postgrex.Protocol (#PID<0.20888.0> ("db_conn_15")) disconnected: ** (DBConnection.ConnectionError) client #PID<0.23667.0> exited
        ................22:22:39.089 [error] Postgrex.Protocol (#PID<0.20877.0> ("db_conn_4")) disconnected: ** (DBConnection.ConnectionError) client #PID<0.23794.0> exited
        22:22:39.105 [warning] Failed to approve selected devices: {:error, :no_devices_selected}
        22:22:39.112 [warning] Failed to reject selected devices: {:error, :no_devices_selected}
        .......22:22:39.243 [error] Postgrex.Protocol (#PID<0.20882.0> ("db_conn_9")) disconnected: ** (DBConnection.ConnectionError) client #PID<0.23844.0> exited
        22:22:39.245 [warning] Failed to clear remote access flag for e04d360a-fbd5-40d4-8a26-c6daf1d02d87:
        Bread Crumbs:
          > Error returned from: Nixstasis.Devices.Device.read

        Unknown Error

        * ** (DBConnection.OwnershipError) cannot find ownership process for #PID<0.20902.0> (Nixstasis.Devices.RemoteAccessLeases)
        using mode :manual.

        When using ownership, you must manage connections in one
        of the four ways:

        * By explicitly checking out a connection
        * By explicitly allowing a spawned process
        * By running the pool in shared mode
        * By using :caller option with allowed process

        The first two options require every new process to explicitly
        check a connection out or be allowed by calling checkout or
        allow respectively.

        The third option requires a {:shared, pid} mode to be set.
        If using shared mode in tests, make sure your tests are not
        async.

        The fourth option requires [caller: pid] to be used when
        checking out a connection from the pool. The caller process
        should already be allowed on a connection.

        If you are reading this error, it means you have not done one
        of the steps above or that the owner process has crashed.

        See Ecto.Adapters.SQL.Sandbox docs for more information.
          (ecto_sql 3.13.4) lib/ecto/adapters/sql.ex:1110: Ecto.Adapters.SQL.raise_sql_call_error/1
          (ecto_sql 3.13.4) lib/ecto/adapters/sql.ex:1011: Ecto.Adapters.SQL.execute/6
          (ecto 3.13.5) lib/ecto/repo/queryable.ex:241: Ecto.Repo.Queryable.execute/4
          (ecto 3.13.5) lib/ecto/repo/queryable.ex:19: Ecto.Repo.Queryable.all/3
          (ash_postgres 2.6.31) lib/data_layer.ex:845: anonymous fn/3 in AshPostgres.DataLayer.run_query/2
          (ash_postgres 2.6.31) lib/data_layer.ex:844: AshPostgres.DataLayer.run_query/2
          (ash 3.15.0) lib/ash/actions/read/read.ex:88: Ash.Actions.Read.run/3
          (ash 3.15.0) lib/ash.ex:3022: Ash.do_read_one/3
          (ash 3.15.0) lib/ash.ex:2930: Ash.read_one/2
          (ash 3.15.0) lib/ash.ex:2883: Ash.read_one!/2
          (ash 3.15.0) lib/ash/code_interface.ex:1781: Ash.CodeInterface.read_get_act!/3
          (nixstasis 0.1.0) lib/nixstasis/devices.ex:942: Nixstasis.Devices.clear_remote_access_device/1
          (nixstasis 0.1.0) lib/nixstasis/devices.ex:101: Nixstasis.Devices.handle_remote_access_owner_down/3
          (stdlib 7.3) gen_server.erl:2434: :gen_server.try_handle_info/3
          (stdlib 7.3) gen_server.erl:2420: :gen_server.handle_msg/3
        ...............22:22:39.594 request_id=GMVnEznMmhBn554AAt6i [warning] Browser request did not resolve to valid Nixstasis operator permissions
        ........................22:22:40.438 request_id=GMVnE2wlfpC4_5cAAtKD [warning] Browser request did not resolve to valid Nixstasis operator permissions
        22:22:40.438 request_id=GMVnE2wpBea4_5cAAtLD [warning] Browser request did not resolve to valid Nixstasis operator permissions
        ...........22:22:40.673 request_id=GMVnE3ogfQh9KUkAAuCC [warning] Browser request did not resolve to valid Nixstasis operator permissions
        ...........................
        Finished in 17.4 seconds (2.1s async, 15.2s sync)
        496 tests, 0 failures
  - stderr:
        warning: Entity without __spark_metadata__ field is deprecated. Entity AshStateMachine.Transition does not define a `__spark_metadata__` field. This field is required to access source annotations. Add `__spark_metadata__: nil` to the defstruct for AshStateMachine.Transition.
          (elixir 1.19.5) lib/enum.ex:961: Enum."-each/2-lists^foreach/1-0-"/2
          (spark 2.4.0) lib/spark/dsl/extension.ex:2222: Spark.Dsl.Extension.__after_verify__/1
          (elixir 1.19.5) lib/enum.ex:961: Enum."-each/2-lists^foreach/1-0-"/2
          (elixir 1.19.5) lib/module/parallel_checker.ex:288: Module.ParallelChecker.check_module/3
          (elixir 1.19.5) lib/module/parallel_checker.ex:125: anonymous fn/7 in Module.ParallelChecker.inner_spawn/6

             warning: Igniter.Inflex.singularize/1 is undefined (module Igniter.Inflex is not available or is yet to be defined)
             │
         659 │                       name: Igniter.Inflex.singularize(references),
             │                                            ~
             │
             └─ lib/resource_generator/spec.ex:659:44: AshPostgres.ResourceGenerator.Spec.do_add_relationships/3
             └─ lib/resource_generator/spec.ex:710:33: AshPostgres.ResourceGenerator.Spec.do_add_relationships/3

             warning: Igniter.Inflex.pluralize/1 is undefined (module Igniter.Inflex is not available or is yet to be defined)
             │
         709 │               if Igniter.Inflex.pluralize(table) == table do
             │                                 ~
             │
             └─ lib/resource_generator/spec.ex:709:33: AshPostgres.ResourceGenerator.Spec.do_add_relationships/3
             └─ lib/resource_generator/spec.ex:715:33: AshPostgres.ResourceGenerator.Spec.do_add_relationships/3
             └─ lib/resource_generator/spec.ex:718:33: AshPostgres.ResourceGenerator.Spec.do_add_relationships/3

             warning: Owl.IO.input/1 is undefined (module Owl.IO is not available or is yet to be defined)
             │
         795 │       Owl.IO.input(label: label, optional: true)
             │              ~
             │
             └─ lib/resource_generator/spec.ex:795:14: AshPostgres.ResourceGenerator.Spec.name_all_relationships/6

             warning: a struct for Plug.Conn is expected on struct update:

                 %Plug.Conn{conn | private: Map.put(conn.private, AshJsonApi.Plug.Parser, content)}

             but got type:

                 dynamic()

             where "conn" was given the type:

                 # type: dynamic()
                 # from: lib/ash_json_api/plug/parser.ex:143:10
                 {:ok, data, acc, conn}

             when defining the variable "conn", you must also pattern match on "%Plug.Conn{}".

             hint: given pattern matching is enough to catch typing errors, you may optionally convert the struct update into a map update. For example, instead of:

                 user = some_function()
                 %User{user | name: "John Doe"}

             it is enough to write:

                 %User{} = user = some_function()
                 %{user | name: "John Doe"}

             typing violation found at:
             │
         152 │              %Plug.Conn{conn | private: Map.put(conn.private, __MODULE__, content)},
             │              ~
             │
             └─ lib/ash_json_api/plug/parser.ex:152:14: AshJsonApi.Plug.Parser.reduce_part/4

        [os_mon] cpu supervisor port (cpu_sup): Erlang has closed
        [os_mon] memory supervisor port (memsup): Erlang has closed

## Capability inventory

- Layout: `monorepo`
- Config roots: `.`, `packages/client`, `packages/server`
- Documentation evidence: `.opencode/commands/close-feature.md`, `.opencode/commands/implement-feature.md`, `.opencode/commands/plan-features.md`, `.opencode/commands/project-alignment-execute.md`, `.opencode/commands/project-alignment-land.md`, `.opencode/commands/project-alignment-review.md`, `.opencode/commands/review-feature-spec.md`, `.opencode/commands/start-feature.md`, `AGENTS.md`, `README.md`, `deploy/compose/README.md`, `docs/book.toml`, `docs/src/README.md`, `docs/src/SUMMARY.md`, `docs/src/architecture.md`, `docs/src/client-server-interface.md`, `docs/src/data-flow.md`, `docs/src/development.md`, `docs/src/features/add-rule-modal-improvements/design.md`, `docs/src/features/add-rule-modal-improvements/tasks.md`, `docs/src/features/ash-api-contract-unification/contract-design.md`, `docs/src/features/ash-api-contract-unification/design.md`, `docs/src/features/ash-api-contract-unification/endpoint-inventory.md`, `docs/src/features/ash-api-contract-unification/tasks.md`, `docs/src/features/authcrunch-role-contract/design.md`, `docs/src/features/authcrunch-role-contract/tasks.md`, `docs/src/features/compose-dev-harness/design.md`, `docs/src/features/compose-dev-harness/tasks.md`, `docs/src/features/dashboard-home/design.md`, `docs/src/features/dashboard-home/tasks.md`, `docs/src/features/device-detail-page/design.md`, `docs/src/features/device-detail-page/tasks.md`, `docs/src/features/go-client-rewrite/design.md`, `docs/src/features/go-client-rewrite/tasks.md`, `docs/src/features/in-memory-ssh-authorized-keys/design.md`, `docs/src/features/in-memory-ssh-authorized-keys/tasks.md`, `docs/src/features/index.md`, `docs/src/features/iot-device-monitoring/design.md`, `docs/src/features/iot-device-monitoring/tasks.md`, `docs/src/features/packaging-deployment-migration/design.md`, `docs/src/features/packaging-deployment-migration/tasks.md`, `docs/src/features/phoenix-ui-polish/design.md`, `docs/src/features/phoenix-ui-polish/tasks.md`, `docs/src/features/production-operations-runbooks/design.md`, `docs/src/features/production-operations-runbooks/tasks.md`, `docs/src/features/report-view-improvements/design.md`, `docs/src/features/report-view-improvements/tasks.md`, `docs/src/features/rich-api-examples/design.md`, `docs/src/features/rich-api-examples/tasks.md`, `docs/src/features/schema-driven-builder-dropdowns/design.md`, `docs/src/features/schema-driven-builder-dropdowns/tasks.md`, `docs/src/features/self-extracting-installer/design.md`, `docs/src/features/self-extracting-installer/tasks.md`, `docs/src/features/server-client-e2e-tests/design.md`, `docs/src/features/server-client-e2e-tests/tasks.md`, `docs/src/features/server-command-allowlist-management/design.md`, `docs/src/features/server-command-allowlist-management/tasks.md`, `docs/src/features/server-provided-frps-token/design.md`, `docs/src/features/server-provided-frps-token/tasks.md`, `docs/src/features/server-stary-script-workbench/design.md`, `docs/src/features/server-stary-script-workbench/tasks.md`, `docs/src/features/starlark-script-system/design.md`, `docs/src/features/starlark-script-system/tasks.md`, `docs/src/modules/client-cli.md`, `docs/src/modules/client-command-handler.md`, `docs/src/modules/client-e2e-harness.md`, `docs/src/modules/client-frp-manager.md`, `docs/src/modules/client-identity.md`, `docs/src/modules/client-starlark-runtime.md`, `docs/src/modules/client-transport.md`, `docs/src/modules/deployment-compose.md`, `docs/src/modules/edge-caddy.md`, `docs/src/modules/edge-frp.md`, `docs/src/modules/index.md`, `docs/src/modules/server-application.md`, `docs/src/modules/server-devices.md`, `docs/src/modules/server-domain.md`, `docs/src/modules/server-e2e.md`, `docs/src/modules/server-monitoring.md`, `docs/src/modules/server-reporting.md`, `docs/src/modules/server-web.md`, `docs/src/modules/shared-e2e-log-viewer.md`, `docs/src/operations/backup-restore.md`, `docs/src/operations/command-policies.md`, `docs/src/operations/ha-scaling.md`, `docs/src/operations/health-checks.md`, `docs/src/operations/incidents.md`, `docs/src/operations/index.md`, `docs/src/operations/secret-rotation.md`, `docs/src/operations/upgrades-rollbacks.md`, `docs/src/planned-features.md`, `docs/src/reference/agent-workflows.md`, `docs/src/reference/contracts.md`, `docs/src/reference/e2e-results.md`, `docs/src/reference/openapi/index.md`, `docs/src/reference/tasks.md`, `docs/src/repository-structure.md`, `docs/src/runtime-boundaries.md`, `docs/src/unknowns.md`, `package.md`, `packages/AGENTS.md`, `packages/client/AGENTS.md`, `packages/client/README.md`, `packages/client/scripts/e2e/README.md`, `packages/server/AGENTS.md`, `packages/server/README.md`
- Test evidence: `packages/client/cmd/nixstasis/frp_session_test.go`, `packages/client/cmd/nixstasis/poll_test.go`, `packages/client/cmd/nixstasis/repl_test.go`, `packages/client/cmd/nixstasis/scripts_test.go`, `packages/client/cmd/nixstasis/test_script_test.go`, `packages/client/internal/commandpolicy/store_test.go`, `packages/client/internal/commands/handler_test.go`, `packages/client/internal/config/config_test.go`, `packages/client/internal/e2e/runner_test.go`, `packages/client/internal/e2e/selector_test.go`, `packages/client/internal/frp/manager_test.go`, `packages/client/internal/identity/detect_test.go`, `packages/client/internal/identity/store_test.go`, `packages/client/internal/script/builtins_exec_test.go`, `packages/client/internal/script/builtins_mqtt_test.go`, `packages/client/internal/script/discovery_test.go`, `packages/client/internal/script/executor_test.go`, `packages/client/internal/script/format_test.go`, `packages/client/internal/script/report_test.go`, `packages/client/internal/script/runtime_test.go`, `packages/client/internal/script/validation_test.go`, `packages/client/internal/sshauth/ipc_test.go`, `packages/client/internal/sshauth/sshd_integration_test.go`, `packages/client/internal/transport/client_runtime_test.go`, `packages/client/internal/transport/register_test.go`, `packages/server/test/mix/tasks/e2e_export_static_test.exs`, `packages/server/test/nixstasis/alerts_test.exs`, `packages/server/test/nixstasis/command_allowlists/category_test.exs`, `packages/server/test/nixstasis/command_allowlists/command_entry_test.exs`, `packages/server/test/nixstasis/command_allowlists/device_policy_assignment_test.exs`, `packages/server/test/nixstasis/command_allowlists/policy_delivery_result_test.exs`, `packages/server/test/nixstasis/command_allowlists/policy_resolver_test.exs`, `packages/server/test/nixstasis/deployment_test.exs`, `packages/server/test/nixstasis/devices/approval_test.exs`, `packages/server/test/nixstasis/devices/device_test.exs`, `packages/server/test/nixstasis/devices/schema_validator_test.exs`, `packages/server/test/nixstasis/devices/ssh_client_test.exs`, `packages/server/test/nixstasis/devices/ssh_key_manager_test.exs`, `packages/server/test/nixstasis/devices/stats_test.exs`, `packages/server/test/nixstasis/devices_bdd_test.exs`, `packages/server/test/nixstasis/devices_test.exs`, `packages/server/test/nixstasis/e2e/data_policy_test.exs`, `packages/server/test/nixstasis/e2e/e2e_test.exs`, `packages/server/test/nixstasis/e2e/journey_selection_test.exs`, `packages/server/test/nixstasis/e2e/log_store_test.exs`, `packages/server/test/nixstasis/e2e/metrics_test.exs`, `packages/server/test/nixstasis/e2e/reporting_test.exs`, `packages/server/test/nixstasis/e2e/retention_test.exs`, `packages/server/test/nixstasis/monitoring/alert_rule_test.exs`, `packages/server/test/nixstasis/monitoring/alert_worker_test.exs`, `packages/server/test/nixstasis/monitoring/command_queue_test.exs`, `packages/server/test/nixstasis/monitoring/offline_checker_test.exs`, `packages/server/test/nixstasis/monitoring/rule_evaluator_test.exs`, `packages/server/test/nixstasis/releases/release_test.exs`, `packages/server/test/nixstasis/reporting/custom_report_list_test.exs`, `packages/server/test/nixstasis/reporting/query_builder_test.exs`, `packages/server/test/nixstasis/reporting/table_filters_test.exs`, `packages/server/test/nixstasis/reporting_test.exs`, `packages/server/test/nixstasis/schema_options/builder_contract_test.exs`, `packages/server/test/nixstasis/schema_options/normalizer_test.exs`, `packages/server/test/nixstasis/schema_options/validator_test.exs`, `packages/server/test/nixstasis/scripts/audit_test.exs`, `packages/server/test/nixstasis/scripts/authorization_test.exs`, `packages/server/test/nixstasis/scripts/validator_test.exs`, `packages/server/test/nixstasis/scripts_test.exs`, `packages/server/test/nixstasis/settings_test.exs`, `packages/server/test/nixstasis_web/channels/terminal_channel_test.exs`, `packages/server/test/nixstasis_web/components/core_components_test.exs`, `packages/server/test/nixstasis_web/controllers/builder_config_validation_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/builder_contract_json_api_test.exs`, `packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/command_policy_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/device_command_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/device_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/e2e_run_result_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/error_html_test.exs`, `packages/server/test/nixstasis_web/controllers/error_json_test.exs`, `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/layout_test.exs`, `packages/server/test/nixstasis_web/controllers/tls_controller_test.exs`, `packages/server/test/nixstasis_web/live/alerts_live_test.exs`, `packages/server/test/nixstasis_web/live/command_policy_live_test.exs`, `packages/server/test/nixstasis_web/live/dashboard_live_test.exs`, `packages/server/test/nixstasis_web/live/device_live_test.exs`, `packages/server/test/nixstasis_web/live/reports_live_test.exs`, `packages/server/test/nixstasis_web/live/script_live_test.exs`, `packages/server/test/nixstasis_web/live_dashboard/e2e_log_presenter_test.exs`, `packages/server/test/nixstasis_web/openapi_contract_test.exs`, `packages/server/test/nixstasis_web/operator_context_test.exs`, `packages/server/test/nixstasis_web/permissions_test.exs`, `packages/server/test/nixstasis_web/plugs/device_permissions_test.exs`, `packages/server/test/nixstasis_web/rate_limiter_store_test.exs`, `packages/server/test/nixstasis_web/runtime_contract_test.exs`
- CI workflows: `.github/workflows/_check_configs.yml`, `.github/workflows/build_caddy_image.yml`, `.github/workflows/build_frps_image.yml`, `.github/workflows/build_server_image.yml`, `.github/workflows/docs.yml`, `.github/workflows/e2e-pages.yml`, `.github/workflows/release_client.yml`
- Ambiguities: none

### Packages

- `.`
  - Manifests: `package.json`, `pyproject.toml`
  - Test evidence:
- `packages/client`
  - Manifests: `go.mod`
  - Test evidence: `packages/client/cmd/nixstasis/frp_session_test.go`, `packages/client/cmd/nixstasis/poll_test.go`, `packages/client/cmd/nixstasis/repl_test.go`, `packages/client/cmd/nixstasis/scripts_test.go`, `packages/client/cmd/nixstasis/test_script_test.go`, `packages/client/internal/commandpolicy/store_test.go`, `packages/client/internal/commands/handler_test.go`, `packages/client/internal/config/config_test.go`, `packages/client/internal/e2e/runner_test.go`, `packages/client/internal/e2e/selector_test.go`, `packages/client/internal/frp/manager_test.go`, `packages/client/internal/identity/detect_test.go`, `packages/client/internal/identity/store_test.go`, `packages/client/internal/script/builtins_exec_test.go`, `packages/client/internal/script/builtins_mqtt_test.go`, `packages/client/internal/script/discovery_test.go`, `packages/client/internal/script/executor_test.go`, `packages/client/internal/script/format_test.go`, `packages/client/internal/script/report_test.go`, `packages/client/internal/script/runtime_test.go`, `packages/client/internal/script/validation_test.go`, `packages/client/internal/sshauth/ipc_test.go`, `packages/client/internal/sshauth/sshd_integration_test.go`, `packages/client/internal/transport/client_runtime_test.go`, `packages/client/internal/transport/register_test.go`
- `packages/server`
  - Manifests: `mix.exs`
  - Test evidence: `packages/server/test/mix/tasks/e2e_export_static_test.exs`, `packages/server/test/nixstasis/alerts_test.exs`, `packages/server/test/nixstasis/command_allowlists/category_test.exs`, `packages/server/test/nixstasis/command_allowlists/command_entry_test.exs`, `packages/server/test/nixstasis/command_allowlists/device_policy_assignment_test.exs`, `packages/server/test/nixstasis/command_allowlists/policy_delivery_result_test.exs`, `packages/server/test/nixstasis/command_allowlists/policy_resolver_test.exs`, `packages/server/test/nixstasis/deployment_test.exs`, `packages/server/test/nixstasis/devices/approval_test.exs`, `packages/server/test/nixstasis/devices/device_test.exs`, `packages/server/test/nixstasis/devices/schema_validator_test.exs`, `packages/server/test/nixstasis/devices/ssh_client_test.exs`, `packages/server/test/nixstasis/devices/ssh_key_manager_test.exs`, `packages/server/test/nixstasis/devices/stats_test.exs`, `packages/server/test/nixstasis/devices_bdd_test.exs`, `packages/server/test/nixstasis/devices_test.exs`, `packages/server/test/nixstasis/e2e/data_policy_test.exs`, `packages/server/test/nixstasis/e2e/e2e_test.exs`, `packages/server/test/nixstasis/e2e/journey_selection_test.exs`, `packages/server/test/nixstasis/e2e/log_store_test.exs`, `packages/server/test/nixstasis/e2e/metrics_test.exs`, `packages/server/test/nixstasis/e2e/reporting_test.exs`, `packages/server/test/nixstasis/e2e/retention_test.exs`, `packages/server/test/nixstasis/monitoring/alert_rule_test.exs`, `packages/server/test/nixstasis/monitoring/alert_worker_test.exs`, `packages/server/test/nixstasis/monitoring/command_queue_test.exs`, `packages/server/test/nixstasis/monitoring/offline_checker_test.exs`, `packages/server/test/nixstasis/monitoring/rule_evaluator_test.exs`, `packages/server/test/nixstasis/releases/release_test.exs`, `packages/server/test/nixstasis/reporting/custom_report_list_test.exs`, `packages/server/test/nixstasis/reporting/query_builder_test.exs`, `packages/server/test/nixstasis/reporting/table_filters_test.exs`, `packages/server/test/nixstasis/reporting_test.exs`, `packages/server/test/nixstasis/schema_options/builder_contract_test.exs`, `packages/server/test/nixstasis/schema_options/normalizer_test.exs`, `packages/server/test/nixstasis/schema_options/validator_test.exs`, `packages/server/test/nixstasis/scripts/audit_test.exs`, `packages/server/test/nixstasis/scripts/authorization_test.exs`, `packages/server/test/nixstasis/scripts/validator_test.exs`, `packages/server/test/nixstasis/scripts_test.exs`, `packages/server/test/nixstasis/settings_test.exs`, `packages/server/test/nixstasis_web/channels/terminal_channel_test.exs`, `packages/server/test/nixstasis_web/components/core_components_test.exs`, `packages/server/test/nixstasis_web/controllers/builder_config_validation_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/builder_contract_json_api_test.exs`, `packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/command_policy_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/device_command_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/device_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/e2e_run_result_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/error_html_test.exs`, `packages/server/test/nixstasis_web/controllers/error_json_test.exs`, `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`, `packages/server/test/nixstasis_web/controllers/layout_test.exs`, `packages/server/test/nixstasis_web/controllers/tls_controller_test.exs`, `packages/server/test/nixstasis_web/live/alerts_live_test.exs`, `packages/server/test/nixstasis_web/live/command_policy_live_test.exs`, `packages/server/test/nixstasis_web/live/dashboard_live_test.exs`, `packages/server/test/nixstasis_web/live/device_live_test.exs`, `packages/server/test/nixstasis_web/live/reports_live_test.exs`, `packages/server/test/nixstasis_web/live/script_live_test.exs`, `packages/server/test/nixstasis_web/live_dashboard/e2e_log_presenter_test.exs`, `packages/server/test/nixstasis_web/openapi_contract_test.exs`, `packages/server/test/nixstasis_web/operator_context_test.exs`, `packages/server/test/nixstasis_web/permissions_test.exs`, `packages/server/test/nixstasis_web/plugs/device_permissions_test.exs`, `packages/server/test/nixstasis_web/rate_limiter_store_test.exs`, `packages/server/test/nixstasis_web/runtime_contract_test.exs`

### Proposed commands

- `root-mise-docs-build` (documentation): argv=`mise run docs:build`; cwd=`.`; provenance=`mise.toml`
- `client-mise-test` (tests): argv=`mise run //packages/client:test`; cwd=`.`; provenance=`packages/client/mise.toml`
- `server-elixir-test` (tests): argv=`mix test`; cwd=`packages/server`; provenance=`manifest-and-test-evidence`

### CI command evidence

- `.github/workflows/_check_configs.yml:45`: `mode="${{ inputs.mode }}"
if [ "$mode" = "images" ]; then
{
echo 'distros=["ubuntu-24.04"]'
echo 'arches=["amd64"]'
echo 'package=images'
echo "version=${GITHUB_REF_NAME#*/[vV]}"
echo 'os-independent=true'
echo 'arch-independent=false'
} | tee -a "${GITHUB_OUTPUT}"
exit 0
fi
if [ "$mode" = "client-release" ]; then
{
echo 'distros=["ubuntu-24.04"]'
echo 'arches=["amd64","arm64"]'
echo 'package=packages/client'
echo "version=${GITHUB_REF_NAME#*/[vV]}"
echo 'os-independent=false'
echo 'arch-independent=false'
} | tee -a "${GITHUB_OUTPUT}"
exit 0
fi
echo "Unsupported mode: $mode" >&2
exit 1` (ci-evidence-only)
- `.github/workflows/build_caddy_image.yml:31`: `cat prod.env >> "$GITHUB_ENV"` (ci-evidence-only)
- `.github/workflows/build_caddy_image.yml:35`: `deploy/compose/scripts/check_runtime_contract.sh` (ci-evidence-only)
- `.github/workflows/build_frps_image.yml:32`: `cat prod.env >> "$GITHUB_ENV"` (ci-evidence-only)
- `.github/workflows/build_frps_image.yml:36`: `deploy/compose/scripts/check_runtime_contract.sh` (ci-evidence-only)
- `.github/workflows/build_server_image.yml:31`: `cat prod.env >> "$GITHUB_ENV"` (ci-evidence-only)
- `.github/workflows/build_server_image.yml:35`: `deploy/compose/scripts/check_runtime_contract.sh` (ci-evidence-only)
- `.github/workflows/docs.yml:54`: `bash docs/scripts/prepare_e2e_results.sh e2e-results docs/src/reference/e2e-results.md` (ci-evidence-only)
- `.github/workflows/docs.yml:57`: `mise exec -- mdbook build docs` (ci-evidence-only)
- `.github/workflows/docs.yml:60`: `if [ -f e2e-results/runs.json ]; then
mkdir -p book/e2e-results
cp -R e2e-results/. book/e2e-results/
fi` (ci-evidence-only)
- `.github/workflows/e2e-pages.yml:60`: `mix local.hex --force
mix local.rebar --force
mix deps.get
MIX_ENV=dev mix ecto.create
MIX_ENV=dev mix ecto.migrate` (ci-evidence-only)
- `.github/workflows/e2e-pages.yml:69`: `NIXSTASIS_DEV_BIND_ALL=true MIX_ENV=dev mix phx.server > /tmp/nixstasis-server.log 2>&1 &
echo $! > /tmp/nixstasis-server.pid` (ci-evidence-only)
- `.github/workflows/e2e-pages.yml:74`: `for _ in $(seq 1 90); do
if curl -fsS http://127.0.0.1:4000/ > /dev/null; then
exit 0
fi
sleep 2
done
echo "Server did not become ready in time."
tail -n 200 /tmp/nixstasis-server.log || true
exit 1` (ci-evidence-only)
- `.github/workflows/e2e-pages.yml:89`: `scripts/e2e/run_all_suites \
--api-url http://127.0.0.1:4000 \
--env local \
--trigger ci \
--protocol-version 1 \
--reports-dir tmp/e2e/reports \
--logs-dir tmp/e2e/logs` (ci-evidence-only)
- `.github/workflows/e2e-pages.yml:102`: `mix e2e.export_static \
--reports-dir ../client/tmp/e2e/reports \
--logs-dir ../client/tmp/e2e/logs \
--pages-dir ../../e2e-pages \
--title "Nixstasis E2E Reports" \
--ref-name "${GITHUB_REF_NAME}" \
--ref-type "${GITHUB_REF_TYPE}" \
--full-sha "${GITHUB_SHA}" \
--max-runs "${MAX_E2E_RUNS}"` (ci-evidence-only)
- `.github/workflows/e2e-pages.yml:117`: `cd e2e-pages
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git add -A
git commit -m "ci(e2e): publish reports for ${GITHUB_REF_NAME}" || exit 0
git push origin HEAD:e2e-results --force` (ci-evidence-only)
- `.github/workflows/e2e-pages.yml:139`: `if [ -f /tmp/nixstasis-server.pid ]; then
kill "$(cat /tmp/nixstasis-server.pid)" || true
fi` (ci-evidence-only)
- `.github/workflows/release_client.yml:35`: `../../deploy/compose/scripts/check_runtime_contract.sh` (ci-evidence-only)
- `.github/workflows/release_client.yml:38`: `packages/client/build/bin/install_makeself.sh
echo "$GITHUB_WORKSPACE/packages/client/build/tools/makeself/bin" >> "$GITHUB_PATH"` (ci-evidence-only)
- `.github/workflows/release_client.yml:43`: `goreleaser release --snapshot --clean` (ci-evidence-only)
- `.github/workflows/release_client.yml:46`: `./build/bin/verify_artifacts.sh` (ci-evidence-only)
- `.github/workflows/release_client.yml:49`: `VERIFY_INSTALLERS=true ./build/bin/verify_artifacts.sh` (ci-evidence-only)
- `.github/workflows/release_client.yml:58`: `goreleaser release --clean --skip=publish` (ci-evidence-only)
- `.github/workflows/release_client.yml:61`: `./build/bin/verify_artifacts.sh` (ci-evidence-only)
- `.github/workflows/release_client.yml:64`: `VERIFY_INSTALLERS=true ./build/bin/verify_artifacts.sh` (ci-evidence-only)
- `.github/workflows/release_client.yml:69`: `shopt -s nullglob
assets=(
dist/nixstasis_*.deb
dist/nixstasis-*.rpm
dist/nixstasis_*_linux_*.tar.gz
dist/makeself/*/*/nixstasis-*-linux-*.run
dist/nixstasis_*_checksums.txt
)
if [ "${#assets[@]}" -eq 0 ]; then
echo "No release artifacts found in dist/." >&2
exit 1
fi
if gh release view "${GITHUB_REF_NAME}" >/dev/null 2>&1; then
gh release upload "${GITHUB_REF_NAME}" "${assets[@]}" --clobber
else
gh release create "${GITHUB_REF_NAME}" "${assets[@]}" --generate-notes --title "${GITHUB_REF_NAME}"
fi` (ci-evidence-only)
