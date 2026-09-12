import ApogeeCore
import OpenAPIRuntime

// A custom transport is an optional integration boundary, not needed by the CLI.
func makeAutomation(
    credentials: AppStoreConnectCredentials,
    transport: any ClientTransport
) -> ReleaseAutomation {
    .init(api: GeneratedAppStoreConnectAPI(credentials: credentials, transport: transport))
}
