import Foundation

/// Well-known meeting apps. Used to (a) name the meeting in the UI and (b) qualify microphone use
/// as "a meeting" rather than Siri or dictation.
enum MeetingApps {
    static let known: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.apple.FaceTime": "FaceTime",
        "com.tinyspeck.slackmacgap": "Slack",
        "Cisco-Systems.Spark": "Webex",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.hnc.Discord": "Discord",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan": "Google Meet",
        "com.loom.desktop": "Loom",
        "com.skype.skype": "Skype",
        "com.ringcentral.glip": "RingCentral",
        "com.gotomeeting.GoToMeeting": "GoTo Meeting",
        "around.co": "Around",
        "com.whereby.whereby": "Whereby",
        "com.apple.iChat": "Messages",
    ]
    /// Browsers count as possible meeting hosts (Meet, Teams web, Jitsi) when the camera is on.
    static let browsers: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
    ]
}
