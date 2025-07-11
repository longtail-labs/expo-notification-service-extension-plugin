/**
 * NSEPluginProps refer to the properties set by the user in their app config file (e.g: app.json)
 */
export type NSEPluginProps = {
    /**
     * (required) Used to configure APNs environment entitlement. "development" or "production"
     */
    mode: Mode;

    /**
     * (required) The local path to a custom Notification Service Extension (NSE), written in Objective-C or Swift. The NSE will typically start as a copy
     * of the default NSE found at (support/serviceExtensionFiles/NotificationService.m or NotificationService.swift), then altered to support any custom
     * logic required.
     */
    iosNSEFilePath: string;

    /**
     * (optional) Language for the NSE. "objc" for Objective-C or "swift" for Swift. Defaults to "objc" for backwards compatibility.
     */
    language?: Language;

    /**
     * (optional) This will enable the Notification Service Extension to filter and modify incoming push notifications before they
     * appear on the user's device. Requires com.apple.developer.usernotifications.filtering entitlement.
     */
    filtering: boolean;

    /**
     * (optional) Used to configure Apple Team ID. You can find your Apple Team ID by running expo credentials:manager e.g: "91SW8A37CR"
     */
    devTeam?: string;

    /**
     * (optional) Target IPHONEOS_DEPLOYMENT_TARGET value to be used when adding the iOS NSE. A deployment target is nothing more than
     * the minimum version of the operating system the application can run on. This value should match the value in your Podfile e.g: "12.0".
     */
    iPhoneDeploymentTarget?: string;
};

export const NSE_PLUGIN_PROPS: string[] = [
    "mode",
    "iosNSEFilePath",
    "language",
    "filtering",
    "devTeam",
    "iPhoneDeploymentTarget"
];

export enum Mode {
    Dev = "development",
    Prod = "production"
}

export enum Language {
    ObjC = "objc",
    Swift = "swift"
}
