import WebKit

/// The scripts that float a page's playing video and bring it back. They run in a world of their own, which
/// remembers the video they floated, so a video the user floated themselves is never brought back by Sela.
@MainActor
enum PictureInPictureScripts {
    static let world = WKContentWorld.world(name: "SelaPictureInPicture")

    /// Floats the largest video that's playing. Resolves to true when it floated.
    static let enter = """
        const playing = [...document.querySelectorAll("video")].filter((video) =>
            !video.paused && !video.ended && video.readyState > 2 && video.videoWidth > 0 && !video.disablePictureInPicture);
        if (playing.length === 0 || document.pictureInPictureElement) return false;
        const area = (video) => video.clientWidth * video.clientHeight;
        const video = playing.sort((a, b) => area(b) - area(a))[0];
        if (video.webkitPresentationMode && video.webkitPresentationMode !== "inline") return false;
        try {
            if (video.requestPictureInPicture) {
                await video.requestPictureInPicture();
            } else {
                video.webkitSetPresentationMode("picture-in-picture");
            }
        } catch {
            if (!video.webkitSetPresentationMode) return false;
            try { video.webkitSetPresentationMode("picture-in-picture"); } catch { return false; }
        }
        window.selaFloatedVideo = video;
        return true;
        """

    /// Brings back the video `enter` floated, if it still floats.
    static let exit = """
        const video = window.selaFloatedVideo;
        window.selaFloatedVideo = null;
        if (!video) return false;
        const wasPlaying = !video.paused;
        if (document.pictureInPictureElement === video) {
            await document.exitPictureInPicture();
        } else if (video.webkitPresentationMode === "picture-in-picture") {
            video.webkitSetPresentationMode("inline");
        }
        // WebKit pauses a video as it comes back into the page. One that was playing carries on.
        await new Promise((resolve) => setTimeout(resolve, 150));
        if (wasPlaying && video.paused) await video.play().catch(() => {});
        return true;
        """
}

/// Lets pages float their videos, as they can in Safari. WebKit only offers the switch on macOS as a private
/// preference, so this checks it's there first. Without it, every request for picture in picture fails.
@MainActor
func allowPictureInPicture(_ preferences: WKPreferences) {
    guard preferences.responds(to: NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")) else { return }
    preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
}
